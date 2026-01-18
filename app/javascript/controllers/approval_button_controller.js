import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]

  connect() {
    // Listen for turbo:submit-start to show loading state
    this.element.addEventListener('turbo:submit-start', this.showLoading.bind(this))
    // Listen for turbo:submit-end to hide loading state (in case of error)
    this.element.addEventListener('turbo:submit-end', this.hideLoading.bind(this))
  }

  showLoading(event) {
    const button = this.element.querySelector('button[type="submit"]')
    if (button) {
      button.disabled = true
      button.style.pointerEvents = 'none'
    }
  }

  hideLoading(event) {
    const button = this.element.querySelector('button[type="submit"]')
    if (button) {
      button.disabled = false
      button.style.pointerEvents = 'auto'
    }
  }
}
